# Apple Voice Progress v1 · VP-C VP_ON内容审核

日期：2026-10-16（Asia/Shanghai）。节点：Stage 7.5 / VP-C_VP_ON_CONTENT_REVIEW。

本轮仅审核23号唯一一次封存证据。新的私人授权、原始证据复核、五个固定窗原样导出及用户本人手动试听已完成。**建议VP-C_RESEARCH_POSITIVE_WITH_LIMITATIONS，交主控复审；不是Apple AEC正式PASS、Test3 PASS或Runtime接入批准。** 未新增设备运行。

## 1. Git基线、范围与新的私人授权

开始时`Apple-Voice-Progress-v1`的HEAD、upstream及实时远端均为`4029ea47f56f8a438d54d9045004a1445177ffb6`，工作区干净。按AGENTS.md定点读取21–23及本次直接相关证据，不重新规划A/B/C或更改历史结论。

另行申请只读23号唯一VP_ON原始PCM及必要manifest、seal、身份/时间元数据，在Git外生成五个固定窗的本机私人WAV，由用户本人手动试听并记录反馈。授权明确包含：三声道重新证明一致后才用ch0代表；禁止自动播放、上传、增强、重采样、A/B旧录音读取和重新录音。用户本次明确回答：**“是”**。没有沿用23号数字统计同意或A/B旧授权。

## 2. 原始证据复核

只定位23号唯一一次`VPC_LIVE_ZH_V1` / `LIVE_HUMAN_RESEARCH` / VP_ON证据。运行身份与本轮固定元数据一致，实际运行次数1；manifest的Release身份与23号及现存固定二进制一致。未重建或执行录音入口。

| 检查 | 本轮重新核验 |
| --- | --- |
| 原生Input / Render | 各136条连续记录、217600帧；16000Hz / 3ch / Float32 planar |
| 固定素材数字Render | ch0对应128000帧，记录mismatches=0；本轮从封存Render对应样本重新计算native SHA，匹配同轮manifest登记。未访问原居民素材或A/B私人PCM |
| 正式覆盖 | 原C覆盖分析为DIGITAL_SAMPLE_SPAN_COVERED，正式13秒及所有required子窗成立；本轮重新检查样本递推、host前进、有效时间和原格式 |
| 失效计数 | lost、overflow、pending、discarded、suppressed、INVALID及缺host/sampleTime均为0 |
| seal / verify | 原seal、footer及receipt校验成立；仅执行正确的只读`verify`目录命令，exit 0，272条/5222400 bytes |
| SHA保护 | 本轮为原容器、seal及manifest建立私人SHA-256快照，导出前后保持一致；没有把这些摘要写入公开报告，也不冒称存在未记录的历史SHA比对 |
| 三声道关系 | 从全部Input原字节重新证实三个声道逐样本相同，非凭RMS或旧报告假设；原始三声道容器完整保留 |
| 满幅样本 | 每声道35个（+1.0为25、−1.0为10），对应相同数字位置；不能重复计为105个独立事件。无NaN/Inf或超范围样本 |

23号通用timestampStatus仍UNVERIFIED，post-roll末端覆盖仍UNVERIFIED，不修改历史结论。内容导出只使用原required窗口已证明覆盖的样本范围，不以post-roll补内容。

## 3. 本轮独立裁切与条件性时间模型

没有把文件开头当t=0，没有使用A/B索引、Render的sampleTime起点或报告中四舍五入的秒数。

本轮Input首sampleTime为620。以本次observationStart的原始absolute局部配对，在相邻Input原host/sample锚间用有理数插值，得到起点约4014.6726667；整数取整起点为4015，逻辑Input帧偏移为3395，故不是文件第0帧。

对原固定计划0、2、4、9、10、13秒，各自采用本轮对应事件的局部(A_before,C,A_after)，只在该事件约0–1.16ms迟到跨度内作同速/no-sleep条件反投影；随后各自在相邻Input原host/sample锚间插值。**没有把一次跨域offset外推全程，也没有将短配对宽度当全部误差。** 这是名义数字窗口的局部仿射模型，不是精确声学起音、传播时间或完整处理延迟标定。

| 原计划边界秒 | 局部模型中的Input sample区间（展示值） | 独立ceil整数边界 |
| --- | --- | ---: |
| 0 | 4014.672667 | 4015 |
| 2 | 36014.808731–36014.809397 | 36015 |
| 4 | 68014.891821–68014.892487 | 68015 |
| 9 | 148015.139902–148015.140569 | 148016 |
| 10 | 164015.167821 | 164016 |
| 13 | 212015.308570–212015.309236 | 212016 |

每个局部配对区间两端的ceil一致，整数边界在所声明模型内稳定；所有局部区间的向上量化均小于1帧（一个原生采样周期62.5µs）。本轮已记录局部offset端点总包络宽2 ticks；这只是观测一致性，不是全程offset恒定或buffer内时钟误差的无条件证明。相邻Input原host锚约100ms；buffer内采用线性插值，未额外校准该模型的物理总误差。

半开时间窗按`[ceil(x_start), ceil(x_end))`选择原始离散采样点。各边界独立计算，因此完整窗及双讲候选窗多一个采样点；不能删帧、重采样或移动边界来凑整秒数。

| 私人WAV标签 | 原计划窗 | 原sampleTime区间，左闭右开 | 逻辑Input帧区间 | 实际帧数 / WAV名义时长 |
| --- | --- | --- | --- | --- |
| A 完整观察 | 0–13秒 | [4015, 212016) | [3395, 211396) | 208001 / 13.0000625秒 |
| B 居民独讲前段 | 2–4秒 | [36015, 68015) | [35395, 67395) | 32000 / 2秒 |
| C 双讲候选 | 4–9秒 | [68015, 148016) | [67395, 147396) | 80001 / 5.0000625秒 |
| D 居民独讲后段 | 9–10秒 | [148016, 164016) | [147396, 163396) | 16000 / 1秒 |
| E 播放后尾段 | 10–13秒 | [164016, 212016) | [163396, 211396) | 48000 / 3秒 |

无额外静默上下文、听感驱动调窗、补时或post-roll样本。在本轮条件模型下，最后纳入的离散采样点仍在原半开计划窗内；不将此升级为无条件或声学时间证明。计划13/5秒与容器名义13.0000625/5.0000625秒明确分开。原保守单调时钟包络和required样本覆盖另行成立；宽包络包含某裁切点不证明该点的亚毫秒精确性。

## 4. 原生副本一致性与隐私

仅输出五个16kHz、mono、IEEE Float32 WAV，ch0代表性以本轮重新证明的三声道全字节相等为前提。只增加RIFF/fmt/fact/data容器封装，不解码再量化音频、不归一化、放大、滤波、降噪、增强、重采样或改变样本顺序。

每份WAV重新解析后的data与原Input ch0对应范围逐字节一致；各自SHA和裁切清单保存在本机私人审核目录。原PCM、receipt、manifest哈希前后不变。五份WAV文件0600、父目录0700、当前用户所有、非symlink，均位于Git之外。

只提供本机文件链接供用户手动播放，没有自动播放、云端上传、ASR/LLM内容识别或新Engine/录音/实验素材播放。没有读取A/B旧私人PCM、访问SSD/quarantine或原ACE3工作区。

## 5. 用户实际试听反馈

用户通过本机私人链接手动试听，执行者没有自动播放或替用户判断。以下保留原始回答，解释只限所问范围，不改写为自动识别、独立逐字转写或无损证明。

| 实际提问范围 | 用户原始回答 | 有限判读 |
| --- | --- | --- |
| A完整段与C双讲段：固定整句、首词“绿色”、尾词“这句话”、自然连续性；突然消音、吞字、断裂、衰减、泵动、爆音、遮盖及可听削波 | **“正常，无异常”** | 对该完整性/首尾/连续性复合问题作正常反馈，未报告所问损伤；支持本次真人语句保留，不是逐词独立转写或一般化保真保证 |
| B居民独讲前段：居民语句/声音可辨性、残余声音、高频噪声或突发杂音 | **“无法听出居民声音，无异常”** | 本段未被听出居民声音，未报告所问异常 |
| C双讲候选段：居民语句/明显回声、遮盖真人、高频噪声或突发杂音 | **“无居民声音，无异常”** | 本段未报告可辨居民回声、遮盖或异常；结合真人正常反馈，支持有限双讲效果 |
| D居民独讲后段：居民语句、真人停止后回声反弹、高频噪声或突发杂音 | **“无法听出居民声音，无异常”** | 本段未被听出居民声音，未报告明显反弹或所问异常 |
| E播放后尾段：居民语句、尾部回声、背景/高频/突发杂音 | **“无居民声音，无异常杂音”** | 本段未报告可辨居民残回声或异常杂音；不是数学零回声 |

固定真人语料仍为“绿色纸船经过小桥，我会继续说完这句话。”。用户是在已知脚本下听自己的单次录音，非盲听辨。没有因反馈修改裁切、补录、换素材或增强音频。

### 5.1 满幅样本与听感

本轮对原样WAV的数字复核确认：A完整段和C双讲段均含35个满幅样本，B/D/E为0，正式窗外没有剩余的满幅样本。三原声道对应位置完全相同，仍记**每声道35个相同位置，而非105个独立事件**。

用户针对包含这些样本的A/C回答“正常，无异常”，未报告提问中的可听削波、爆音、泵动或明显损伤。没有将35个点单独制作试听片段，也没有逐点做听感因果定位；只能说**本次整段试听未报告明显可听损伤**，不能说这些样本永远无失真、AGC无影响或音质无损。数字触顶观察继续保留。

## 6. 四维结果、研究建议与剩余限制

继承23号实际采集后的现场提问和原答：被问及居民确实外放、真人连续讲话时居民同时讲话超过1秒、自然说完整句及提示正常、无现场变化，用户回答**“1、2、3、4都确认正常”**。本轮没有重新创造现场见证。

物理持续双讲的有限证据链为：

1. 同轮固定居民素材身份及严格Render原样匹配成立；未依赖其他轮次PCM。
2. 原计划near控制区间保守纳入的Render ch0有78400帧、77595非零样本，分布于多个原生sampleTime秒格；这只证明适当持续数字播放，不把非零数写成发声秒数。
3. 同轮Input完整段与固定双讲候选段由本人实际试听，对指定真人整句/首尾/连续性问题反馈正常，无所问明显损伤。
4. 同轮现场曾明确见证自己连续讲话时仍听到居民外放超过1秒，而不是只有cue或播放命令重叠。
5. 原始host/sample及局部配对支持数字关联；传播、处理/输出延迟和精确声压未标定，裁切使用第3节条件模型。

据此可支持**WITNESSED_GT_1S_WITH_LIMITATIONS**，不是由4–9秒计划窗或WAV长度直接推断物理重叠5秒。精确物理起止/持续时长仍未测量。Input未听出居民回声不会反过来否定这条独立现场见证与数字播放链。

| 维度 | 本轮建议裁定 | 证据边界 |
| --- | --- | --- |
| ENGINEERING_VALIDITY | **ACCEPTED_ENGINEERING_ONLY / EXPORT_BYTE_IDENTITY_VERIFIED** | 继承主控对23的工程接受；本轮重新verify、格式/计数/连续性、required覆盖、匹配及原样导出核验通过；不把post-roll改为已覆盖 |
| PHYSICAL_OVERLAP_EVIDENCE | **SUPPORTED_WITH_LIMITATIONS；WITNESSED_GT_1S_WITH_LIMITATIONS** | 同轮现场>1秒见证、Render和Input内容相互支持；不是独立声场计时、真实声压或精确5秒保证 |
| NEAR_END_PRESERVATION | **DOUBLE_TALK_PRESERVED（本次有限样本支持）** | 用户对完整段和候选段的整句、首尾、自然连续与异常复合问题反馈正常；无新增ASR、VAD或RMS内容判定 |
| ECHO_RESIDUAL | **LIMITED_SUPPRESSION_SUPPORTED / INTELLIGIBLE_RESIDENT_ECHO_NOT_REPORTED** | B/C/D/E均未被听出居民声音/语句，未报告遮盖、反弹或所问异常；不证明零回声、零所有声学残留或净AEC增益 |

四个条件在本次有限证据下同时得到支持：工程有效；实际持续物理双讲>1秒有有限见证；真人整句与首尾正常、未报告明显误消音；居民可懂回声得到有限抑制。因此**建议VP-C_RESEARCH_POSITIVE_WITH_LIMITATIONS**，研究收口决定交主控，不自行宣告正式VP-C或Test3通过。

仍须保留：单人/单次/固定设备位置与音量/已知脚本非盲评价；USB唯一物理来源UNVERIFIED；Input三声道非三路独立信息；35个满幅观察；post-roll末端未知；局部时间模型和未标定声压/处理时延；Apple VP含AGC等整体处理，未拆出纯AEC贡献。没有正式Test3重复矩阵、Runtime声源资格、语义插话或取消安全的新验收证据。

本轮没有证据要求标记DOUBLE_TALK_DEGRADED、NEAR_END_SUPPRESSED或ECHO_RESIDUAL_SIGNIFICANT；这仅是未在本次已听样本中被报告，不排除其他条件下发生。

## 7. TECHNICAL_REVIEW / ENGINEERING_REVIEW / EVIDENCE_REVIEW

**TECHNICAL_REVIEW：FINITE_DOUBLE_TALK_PATH_SUPPORTED / FORMAL_AEC_NOT_ESTABLISHED。** 同轮原生数字身份、时间和内容证据保持分层，真人与回声两项均观察；不把Render当声压、不把VP整体等同纯AEC或用Input安静推断成功。

**ENGINEERING_REVIEW：ACCEPTED_ENGINEERING_ONLY / CONTENT_EXPORT_VERIFIED。** 原工程基线未改，独立verify成功，三声道重新相等证明、固定窗裁切、WAV data原样及SHA/权限核验通过。时间方法经独立只读复核，无CRITICAL/MAJOR；向上量化表述采用“小于1帧”，不制造多余精度。本轮没有源码、构建或371项回归重跑，检查仅限当前离线证据、文档、Git与隐私。

**EVIDENCE_REVIEW：VP-C_RESEARCH_POSITIVE_WITH_LIMITATIONS（建议，REVIEW_PENDING）。** 用户实际听感和同轮现场见证支持有限双讲积极结论；所有原答保留。没有自动内容识别、声学无损或数学零回声证明，也没有正式安全资格授予。内容证据边界另经独立只读报告复审，未发现CRITICAL/MAJOR；该复核不代替主控裁决。

## 8. Stage7 Forbidden Checklist与收口

| 检查 | 裁定 |
| --- | --- |
| Stage/macOS/六红线 | PASS；只做Stage7.5单机独立证据审核，无新平台或Stage8 |
| Qwen/Provider/Runtime/Test2 | PASS；无调用/源码/API/实时协议/generation变化，无声源资格、interrupt/cancel/clear或Runtime接入 |
| DR/Studio/Memory/Session/Store/调度 | PASS；无schema、所有权、持久化或后台功能变化 |
| 冻结实现、历史合同与报告 | PASS；源码、参数、01–23及正式Test3合同不变；不操作原ACE3、SSD/quarantine或历史A/B私人PCM |
| 设备与内容授权 | PASS；新的本轮只读/私人导出/本人试听同意后才读PCM；未启动Engine/录音或播放实验素材，未自动播放录音 |
| 私人与Git边界 | PASS；原件和五份原幅度WAV在Git外，0600/0700；无上传、ASR/云端处理；只新增本文，不提交私人路径、身份/音频SHA、PCM/WAV、登记或原始日志 |

Stage7结论：**PASS**。触碰红线：无。修改文件：仅本文。是否改代码/Runtime API/DR schema/新增平台target/进入Stage8：均否。完成本轮提交推送后停止，等待主控研究结论复审；不自动进行任何补证、播放、录音或下一阶段。

```text
VP-C Device Run = ACCEPTED_ENGINEERING_ONLY
VP-C Content Review = REVIEW_PENDING
VP-C Research Result = VP-C_RESEARCH_POSITIVE_WITH_LIMITATIONS (RECOMMENDED / REVIEW_PENDING)
Physical Overlap = WITNESSED_GT_1S_WITH_LIMITATIONS
Near End = DOUBLE_TALK_PRESERVED (LIMITED_SAMPLE_SUPPORT)
Echo Residual = LIMITED_SUPPRESSION_SUPPORTED
Additional Device Run = NOT_AUTHORIZED
VP-D/E = NOT_AUTHORIZED
Runtime Integration = NOT_AUTHORIZED
USB Unique Source = UNVERIFIED
Apple AEC Formal PASS = NOT_ESTABLISHED
Test3 = BLOCKED
Test3.execution_authorized = false
```
