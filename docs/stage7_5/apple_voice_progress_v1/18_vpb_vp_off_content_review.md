# Apple Voice Progress v1 · VP-B VP_OFF私人内容试听复核

日期：2026-10-15（Asia/Shanghai）。节点：Stage 7.5 / VP-B_VP_OFF_CONTENT_REVIEW。

**有限内容裁定：VP_OFF_BASELINE_CONTENT_SUPPORTED。** 用户实际试听后确认A/B完整可辨、首尾清楚，C轻声自然可懂、内容完整且首尾清楚，均未听到所询问的明显损伤；D有少量杂音但不妨碍语音判断。这只支持17号唯一一次VP_OFF样本的内容基线，不是VP-B整体PASS、VP_ON保真证据或Test3 PASS。

## 1. 基线、授权及唯一原始证据

开始时 `Apple-Voice-Progress-v1` 的HEAD、upstream及实时远端均为 `eba2eec373eaf1bbbe85a084837d3571c002576b`，工作区干净。仅新增本文，不修改工具源码、协议或01–17历史报告，不重新录音或重复工程验证。

先读取AGENTS.md及[17号设备报告](17_vpb_vp_off_device_run.md)，未先行读取私人PCM。随后用户对本节点明确回复：**“明确授权本次只读、私人导出及本人手动试听”**。授权范围为17号唯一一次既有VP_OFF PCM及必要manifest/封存收据、Git外私人试听副本、用户本人手动试听及本地完整性/内容审核；不含自动播放、上传、音频增强或设备实验。

原始证据通过本地固定输入记录定位，交叉核对manifest的运行身份、研究别名、build身份、VP_OFF模式、`VPB_LIVE_ZH_V1` / `LIVE_HUMAN_RESEARCH`及唯一调用计数。Input为原生48kHz、mono、Float32，共126条、604800 frames；与17号见证一致。没有读取其他历史私人PCM、重新登记设备或重新选一次运行。

在导出前，用原固定Release的只读 `verify` 做本次数据完整性检查，返回exit0、container_complete=true、invalid_reasons=0；原容器及二进制封存收据匹配，252条记录、6864480 bytes PCM。此操作只读文件，不创建或启动Engine、请求权限或重做设备工程实验。manifest/实际Input身份另行交叉核验，未把容器verify当作内容判断。

原容器、manifest及收据等原始文件的SHA-256在导出前、后及用户反馈后全部一致；原身份、原文件摘要及导出摘要仅保存在本机私人审核记录中，不公开运行UUID、设备身份或私人路径。

## 2. 固定时间定位、导出范围与限制

从原容器逐record只读定位Input，核对原ASBD、全部sampleTime/hostTime有效性及连续sample序列。没有从17号四舍五入的秒数反推样本，也没有拟合全程absolute/continuous固定偏移。

以原observationStart的局部A_before/A_after区间和相邻Input host/sample锚点为依据，按原生48000Hz在前驱锚点内定位；事先固定采用ceil选择不早于该局部起点的首个名义样本。得到源sample区间 **[6214, 582214)**，连续576000 frames。试听前即固定全部区间，之后没有按听感平移、挑选或替换。

**“完整12秒副本”指576000帧的48kHz名义12秒，不是控制C域0–12秒与每一物理样本精确相等的新证明。** 起点帧取整约6.58µs，小于一帧20.83µs；这一数字不是总时间误差。相邻块首host锚点约100ms，块内位置依赖原生时间戳/采样率映射模型；硬件时钟、实际声学起音与用户反应不由该模型测得。

选定范围位于原评分覆盖证明的已记录样本跨度内。末端分别用其前/后邻近host/sample锚点按原生速率复核，两种局部映射均在实际POST_ROLL边界之前，较保守的一种约提前40.799ms；局部模型差约0.67µs。**这只是模型下的交叉检查，不把模型差或帧量化宣称为物理总误差上限。** 未使用post-roll样本区间补拼或延长内容，也没有以本轮裁切补全17号post-roll未验证结论。

所有子片段仅从同一预定完整副本对应的原字节区间生成；前后各保留0.5秒计划静默上下文。上下文允许重叠，不是额外实验或修改评分窗口；计划静默不等于实测绝对安静。

| 副本 | 原评分目标 | 在完整副本中的固定导出区间 | frames / 名义时长 |
| --- | --- | --- | --- |
| 完整观察段 | 原0–12秒观察及D背景 | [0, 12)秒 | 576000 / 12秒 |
| A正常讲话 | 原2–5秒 | [1.5, 5.5)秒；副本内帧[72000, 264000) | 192000 / 4秒 |
| B自然短句 | 原5.5–7秒 | [5, 7.5)秒；副本内帧[240000, 360000) | 120000 / 2.5秒 |
| C轻声讲话 | 原7.5–10秒 | [7, 10.5)秒；副本内帧[336000, 504000) | 168000 / 3.5秒 |

A/B/C的内容判断使用这些固定片段及相邻上下文，最晚只到副本10.5秒；不以完整副本末端或未验证post-roll补语句首尾。这里支持的是可听辨首尾词，不是毫秒级起尾损失、处理时延或逐音素无损。

## 3. 试听副本一致性与隐私

四份WAV均为 **IEEE Float32 / 48kHz / mono**，写入格式头及fact帧数后直接复制原Input payload；未经过整数PCM中转、下混、重采样、归一化、放大、滤波、降噪或增强。没有ASR、LLM或语音模型参与听辨。

导出后重新解析每份RIFF/WAVE的fmt、fact、data与长度，核验frames和格式；WAV音频data与原容器选定样本字节逐段一致，二者payload摘要相同。用户反馈后再次核对全部WAV文件摘要，未发生变化。只增加WAV封装和私人审核记录，没有覆盖原始资产。

试听目录在Git外、本人所有、0700；四份WAV及审核记录为非symlink普通文件、0600。只向用户提供本机文件链接，由用户手动播放；没有自动启动播放器、音频Engine或录音，没有上传音频、设备身份、原始日志、私人摘要或路径。本轮没有新建试听服务器或云端页面。

## 4. 用户原始反馈与首尾内容

分别向用户询问A/B/C完整语句、首尾词、缺词/断裂及明显失真或杂音遮盖；C额外询问轻声能否自然听懂。另询问完整副本计划静默段。以下逐项保留实际回答，没有替用户选择或用数字统计推断。

| 项目及预登记语料 | 询问的首尾词 | 用户原始反馈 | 本轮有限判断 |
| --- | --- | --- | --- |
| A：“今天下午天气不错，我想出去散步。” | 今天 / 散步 | “完整可辨，首尾清楚，未听到上述明显损伤” | 正常连续讲话内容及首尾词可辨得到支持 |
| B：“我听见了。” | 我 / 听见了 | “完整可辨，首尾清楚，未听到上述明显损伤” | 自然短句内容及首尾词可辨得到支持 |
| C：“请把声音调低一点。” | 请 / 一点 | “轻声自然可懂，内容完整，首尾清楚，未听到上述明显损伤” | 本次较轻讲话自然可懂、内容及首尾词可辨得到支持 |
| D：计划静默/环境背景 | 不适用 | “有少量杂音，但不妨碍语音判断” | 杂音单列，不自动判失败，不删除或改名 |

录音当轮用户已经确认“提示及时，三句均按提示自然说完，无已知异常或现场变化”；本轮又实际试听上述副本。因此现场发声自述与音频内容反馈分别保留，不互相冒充。

本次听者就是发声用户，知晓固定脚本，属于**非盲、单听者、单次样本**；有期待偏差和主观判断限制。没有独立第二听者、原声同步对照或客观保真测量。没有把“未听到明显损伤”扩大为音质无损、真实幅度不变或所有弱/短语音均被保留。

## 5. 内容等级与既有边界

**VP_OFF_BASELINE_CONTENT_SUPPORTED。** A/B/C全部满足本任务的有限人工内容规则：整句可辨、预登记首尾清楚，C轻声自然可懂，未报告缺词、断裂、明显失真或遮盖。D少量杂音不妨碍判断。该结论来自实际用户反馈，不来自RMS、VAD或自动语义模型。

只确认这一次VP_OFF的有限内容基线；不是VP-B整体PASS、NEAR_END泛化保证、VP_ON近端保留、持续双讲、Apple AEC PASS或Test3 PASS。没有把OFF称为ADC原始真值，也没有给USB唯一物理来源或Runtime声源资格升级。

17号中的post-roll完整数字覆盖未证实、通用timestampStatus=UNVERIFIED及设备/时间测量限制原样保留。当前内容可辨不能追溯改写其工程字段，不能补齐精确声学时序或所有异步清理证据。原声源资格false、Runtime NOT_EXERCISED及正式Test3合同不变。

## 6. 三维复审与Stage7 Forbidden Checklist

**TECHNICAL_REVIEW：LOCAL_NATIVE_EXPORT_VERIFIED_WITH_TIMING_LIMITATIONS。** 原生格式、固定局部时间映射及样本选择、四份WAV逐字节一致性成立；模型、帧量化和物理边界局限明确。没有新的声学阈值、窗口、转换器或音频架构。

**ENGINEERING_REVIEW：READ_ONLY_CONTENT_WORKFLOW_COMPLETED。** 只读原证据、生成私人副本、接收本人手动试听结果；原始文件及副本复核一致。没有源码修改、重新构建或重跑313项测试/设备工程回归；独立音频工具仅运行只读数据verify，其余为离线文件/文档/Git处理，不含record、vp-b、VP_ON、Engine或权限操作。

**EVIDENCE_REVIEW：VP_OFF_BASELINE_CONTENT_SUPPORTED / REVIEW_PENDING。** 支持本次正常/短句/较轻语音的可懂内容和首尾词。仅有限OFF基线，主控仍需审核；任何下一臂不由本结论自动授权。

| Stage7 Forbidden Checklist | 裁定 |
| --- | --- |
| Stage/macOS/六红线 | PASS；无新平台、Stage8或六红线变更 |
| Qwen/Provider/Runtime/Test2 | PASS；无Qwen、STS、Provider、正式I/O、RuntimeCore/API、generation、用户轮次、声源资格或中断/取消动作；Test2未改 |
| DR/Store/Studio/Memory/Session | PASS；无schema/fixture/居民资产写入，无调度或状态所有权扩展 |
| 冻结代码/历史报告 | PASS；所有源码、协议、01–17及正式Test3合同保持；未操作原ACE3工作区、SSD/quarantine |
| 设备与授权 | PASS；读取/导出前取得本次明确授权，仅本次既有数据；无新录音、外放实验、Engine、权限/路由/Mic Mode操作或自动重试 |
| 私人数据与Git | PASS；仅本文进入Git，私人PCM/WAV、原始manifest/收据、身份、摘要、反馈记录及路径留本机Git外；无云端或自动播放 |

**Stage7结论：PASS。触碰红线：无。修改文件：仅本文。是否改源码/Runtime API/DR schema/新增平台target/进入Stage8：均否。** 本轮已授权文档提交可以完成；不自动开始任何下一阶段。

```text
VP-B VP_OFF Content = VP_OFF_BASELINE_CONTENT_SUPPORTED / REVIEW_PENDING
VP-B VP_ON = NOT_AUTHORIZED
VP-C/D/E = NOT_AUTHORIZED
Runtime Integration = NOT_AUTHORIZED
Test3 = BLOCKED
Test3.execution_authorized = false
```

仅提交本脱敏报告并推送后停止，等待主控复审。
