# Apple Voice Progress v1 · VP-C单次VP_ON实机记录

日期：2026-10-16（Asia/Shanghai）。节点：Stage 7.5 / VP-C_SINGLE_VP_ON_DEVICE_RUN。

**唯一一次VP_ON采集已完成，数字工程证据支持ENGINEERING_VALID；本节点交主控复审。实际物理重叠、真人保留、居民残回声仍EVIDENCE_UNVERIFIED。** 没有导出WAV、试听本次Input、识别内容或进行声学PASS裁定；没有重试、切换VP_OFF、重做A/B或进入Runtime。

## 1. Git、Release与执行范围

执行前分支`Apple-Voice-Progress-v1`的HEAD、upstream及实时远端均为`5e9c9254e6191e6411fa78d06c45934be041d2ec`，工作区干净。读取AGENTS.md、21/22及VP-C直接相关源码，继承批准实现与MAJOR修复，不重新开发。

| 身份 / 环境 | 本轮见证 |
| --- | --- |
| 实际系统 | Apple M4；macOS 26.6.2；沿用原Mac mini与登记设备 |
| Release二进制SHA-256 | `099b328f4bcc28bd111d8e02a358665e73b8bf0a354d870959ca0d9d24a3ec5b` |
| 资源bundle身份SHA-256 | `0707669eea2c564470f1adabb2862823ea808355dae76dd608aaa3cdde24b4e9`；3个资源文件 |
| 签名与宿主 | ad hoc，Identifier=`apple-vp-reference`；`codesign --verify --strict`成功；Codex直接CLI宿主 |
| 执行身份一致性 | 固定既有Release，无中途重建/重签；运行manifest的build身份匹配，执行后二进制和资源摘要不变 |
| 实际执行 | 一个`vp-c`命令、VP_ON_ONLY、一轮Engine/Recorder生命周期、一次居民play；exit 0仅是结束状态 |
| 本轮代码/回归 | 不改源码或资源，不重跑371项；复用22号已审核构建与回归基线。本轮新增证据是真实运行及封存后的数字核验 |

只新增本文。01–22历史结论、独立工具冻结源码及生产系统均不修改。Release摘要是代码构建身份，不是私人素材或设备身份；私人身份和素材双SHA不在本文公开。

## 2. 分立授权与材料内容准入

本次没有沿用A/B旧录音同意：

1. 用户对本次只读既有P4登记、固定素材登记、必要构建/运行元数据及素材离线核验明确回答“是”。没有读取历史VP-A/B私人PCM。
2. 素材语义初始未确认时，用户选择“尚不能确认，需要手动核验素材”。提供既有原素材的本机位置，由用户自行播放，未自动播放、转换、裁剪或替换。之后用户回答：**“已试听，持续讲话且内容可区分”**，对应原素材2–7秒与固定近端语句的区别。该见证只用于素材准入，不是本次双讲录音内容审核或测量级发声时长。
3. 完成无Engine准入后，另行明确申请本次唯一VP_ON的扬声器外放、真人麦克风录音、私人全声道封存及自动完整性/数字统计；同时列明16秒admission、13秒正式观察、0.5秒post-roll、停止播放器/其他采集程序及现场设置不变。用户明确回答“是”。
4. 唯一真实命令还要求用户点击原生确认窗口；本轮preflight回执为用户已确认且窗口可见。技术开关没有替代现场授权。

本次授权不包含Input内容试听、WAV导出、ASR/云端模型或追加采集，均未执行。

## 3. 固定素材、原登记及无Engine准入

原P4登记文件仍在，当前用户所有，父目录0700、文件0600、非symlink；现有字节SHA与既有A/B登记元数据一致，原USB/Built-in匿名身份一致，**REGISTRATION_VALID，未重新登记或改写身份**。

原历史居民素材沿用此前用户明确指定并批准的固定8秒版本。文件SHA及解码native PCM SHA同时匹配既有登记，本轮没有重新裁剪、归一化、增强、生成或覆盖原资产。独立RIFF/Float32检查与既有无Engine准入辅助程序调用的`PCMSourceMaterial.load`、`VPAMaterialSafety.inspect`结果一致：

| 素材检查 | 结果 |
| --- | --- |
| 原生格式 / 帧数 | 16000Hz / mono / Float32；128000 frames，即8秒 |
| 非有限 / 超范围样本 | 0 / 0 |
| 绝对峰值 / 恰好满幅样本 | 0.687774658203125 / 0 |
| 文件与native双SHA | 均匹配；具体摘要仅保存在本机私人记录 |
| 源区间2–7秒 | 每个原定1秒段均有数字信号；持续居民讲话与语句可区分性由本次用户手动素材试听支持，未以RMS/非零计数代替语义 |

首次本地元数据检查曾把A的描述性状态`REGISTRATION_VALID_UNCHANGED_FROM_P4_AND_FINAL_OFF`误按B的简写状态`REGISTRATION_VALID`逐字比较，提前停止该检查。只读核对原登记字节及双方摘要/身份相同后，消除了标签差异；没有更换登记、设备getter或放宽真实设备守卫，也没有启动音频。

无Engine辅助检查只读取已有登记、固定素材、HAL默认设备/占用、输出音量及可读取的Mic Mode，不创建/启动Engine。默认USB输入和Built-in输出与原登记一致；输入未被其他程序运行，已知Aftelle/采集程序进程检查无命中。已有麦克风权限为AUTHORIZED，没有申请、重置TCC或修改隐私设置。

输出音量读值0.7619839906692505，与既有条件一致；preferred/active Mic Mode原始值均为0，前后不变。它们是API可读取的进程属性，不额外宣称已排除所有系统级Mic Mode影响。输入增益、位置及现场环境无法完全由这些属性证明，依赖本次用户明确确认未变。

采集前可用磁盘约13.01GiB。创建全新的仓库外私人证据目录，未覆盖任何A/B或先前证据。所有正式PCM、seal、prepared/manifest及私人登记/身份记录留在本机；原生证据文件0600，运行目录0700，用户所有且非symlink。

## 4. VP配置、图与设备路由

| 项目 | 配置后 / 运行中 / 停止后 |
| --- | --- |
| 模式 | VP_ON；inputEnabled=true、outputEnabled=true；配置前两端为false，AGC=false |
| bypass / input mute / AGC | false / false / true；属性可读取，三阶段快照一致 |
| Input / mixer / output客户端格式 | 各16000Hz、3声道、Float32、non-interleaved；运行与停止快照一致 |
| 接图前格式 | Input已有3声道，mixer/output为2声道；接图后均为3声道。保留原始快照，没有把接图前格式写成运行格式 |
| 默认输入 / 输出 | 原登记USB / Built-in；配置、运行、停止及无Engine后检均一致；本轮HAL nominal rate分别为16000 / 48000Hz，与准入基线一致 |
| 两个node的设备呈现 | inputNode/outputNode均与Built-in输出快照一致；普通deviceBindingStatus仍为UNAVAILABLE，使用既有批准研究准入政策 |
| 来源限制 | USB Source仍SOURCE_SUPPORTED_ONLY；不能把默认USB、node呈现或本轮采集成功改写成USB唯一物理来源确认 |

仍为同一个AVAudioEngine：固定素材经player→mainMixer→output，Input在原VP处理后Tap处记录；无麦克风回送、AEC3、HAL Gate、Provider、Qwen或Runtime。没有修改图、Driver、Tap、Recorder、设备路由、音量、增益或Mic Mode。

## 5. 实际时间与提示

协议`VPC_LIVE_ZH_V1`、固定近端语句“绿色纸船经过小桥，我会继续说完这句话。”不变。所有deadline仍从同一observationStart计算，没有顺延窗口、补时或调参。

- arm至observationStart：**0.361447秒**，双流有效PCM预热后才开窗。
- arm至beforeStop：**13.862014秒**；stopRequest：**13.862052秒**。所有记录中的callback进入时刻均位于16秒admission内，未触发时间预算错误。未把CLI总墙钟时长当成录音时长，也不宣称阻塞Apple API具有抢占式截止保证。
- 九条局部事件完整；timebase为125/3 ns/tick，事件配对宽度0–1 tick，最大约41.667ns。这个局部读取宽度不是跨事件包络宽度、输出延迟或声学到达误差。
- 六条cue的请求与显示回执均有效、窗口可见。下表相对时间为原始continuous tick计算的展示摘要，完整原tick仅保存在私人证据中。

| cue | 计划秒 | 实际请求秒 | 实际显示秒 | 起点显示迟到ms |
| --- | ---: | ---: | ---: | ---: |
| QUIET | 0 | 0.001415 | 0.002097 | 2.096542 |
| RESIDENT_START | 2 | 2.001159 | 2.001287 | 1.286708 |
| NEAR_CONTINUOUS | 4 | 4.001191 | 4.001779 | 1.779375 |
| RESIDENT_AFTER | 9 | 9.001201 | 9.001767 | 1.766833 |
| TAIL | 10 | 10.001202 | 10.001319 | 1.318542 |
| POST_ROLL | 13 | 13.001193 | 13.001745 | 1.745000 |

均小于原250ms门。独立playRequest在2.004226秒；只有一次play。beforeStop在13.500567秒，固定13秒评分与0.5秒独立post-roll均未改动。实际near显示到下一request的控制可用跨度为4.9994215秒；它不是用户发声或物理重叠时长。

## 6. 双流PCM、连续性与正式窗口覆盖

原始容器及manifest的本轮独立只读解析一致：

| 项目 | Input | Render |
| --- | ---: | ---: |
| 原生格式 | 16kHz / 3ch / Float32 planar | 16kHz / 3ch / Float32 planar |
| 记录 / 帧数 | 136 / 217600 | 136 / 217600 |
| 原生样本总覆盖 | 13.6秒 | 13.6秒 |
| 每条记录 | 1600 frames | 1600 frames |
| 相邻raw host锚间隔 | 99.9966–100.0018ms | 99.9959–100.0018ms |
| 实际callback进入间隔 | 91.1546–129.6721ms | 95.7672–128.1996ms |
| callback间隔中位数 | 96.2230ms | 96.0185ms |
| host/sample有效性、sample递推 | 全部有效，精确连续，无断样 | 全部有效，精确连续，无断样 |

13.6秒是实际原生连续样本数量，不是宣称全部13.5秒计划阶段端点均已获证；两路起点和末buffer锚也不同。callback进入时刻与AVAudioTime.hostTime另列，未把名义100ms音频块时长冒充精确回调调度。未设新的回调性能PASS阈值。

原正式13秒、quiet、residentPlay、residentBefore、doubleTalkCandidate、residentAfter、tail的**Input/Render前后锚、连续样本及名义跨度检查全部成立**：`DIGITAL_SAMPLE_SPAN_COVERED`。正式13秒锚点间样本跨度各为209600帧（13.1秒），这是包住原计划窗的保守数字跨度，不是延长评分。

计划边界仍用局部时钟单调包络，不假设全程offset恒定；部分子窗包络较宽，因此其锚点样本跨度可能大于名义窗口，不等于实际双讲持续该时长。

**post-roll covered=false，单独UNVERIFIED。** 末端没有足够晚的后继host锚，不能靠最后buffer帧数或控制完成推断完整0.5秒已交付。该窗按原批准实现为非评分、非required；不补入正式窗，也不自动否决已独立证明的正式13秒覆盖。没有放宽或修改检查器。

## 7. 固定素材对应与分阶段数字Render

封存后原检查器结果：

- `EXACT_REGISTERED_SOURCE_SEQUENCE_SUPPORTED`：Render **ch0**完整128000帧原样匹配已准入固定素材，mismatches=0；保留leading silence的整数sample对齐起点为37528。
- 匹配起点前后raw host锚满足原play因果门，`playCausalityVerified=true`，不是提前播放或直到near阶段才开始的素材。
- Render ch1/ch2全程为零，没有完整匹配的素材序列；不因此猜测内部通道角色或丢弃声道。
- `MATCHED_SOURCE_AND_DOUBLE_TALK_DIGITAL_SIGNAL`成立；整体`DIGITAL_DUAL_STREAM_AND_RENDER_PRESENT`成立。原本担心的严格素材兼容性未在本轮阻断，但不保证其他设备/运行同样匹配。

| 分阶段分布（实际display→下一request内的完整buffer） | 每声道纳入帧数 | ch0非零样本 | ch1/ch2非零样本 |
| --- | ---: | ---: | ---: |
| 居民独讲前段，计划2–4秒 | 30400 | 18573 | 0 / 0 |
| 计划双讲段4–9秒的实际控制区间 | 78400 | 77595 | 0 / 0 |
| 居民独讲后段，计划9–10秒 | 14400 | 14394 | 0 / 0 |

near区间ch0首末非零sampleTime为68376–146775，分布于原生sampleTime的6个一秒格；超过原数字持续性门。格子和非零占用不是VAD、语音活动秒数或真实声学时间；边界buffer被保守排除，分阶段计数不要求等于全程非零总数。

真实player状态在play后为true、stop后为false；Render确有对应数字内容。**player状态、Render匹配和用户现场听到声音相互补充，但Render仍不是扬声器声压或精确空气传播/物理双讲计时。** 没有用计划播放与提示重叠直接判定持续物理双讲。

## 8. 全声道数字统计与满幅观察

对本次原始封存字节重新解析，逐声道统计与工具结果一致；解析前后原容器SHA未变。没有写回PCM、改变幅度或制作试听副本。

| 流 / 声道 | 样本数 | peak | RMS | 满幅 | 非有限 / 超范围 |
| --- | ---: | ---: | ---: | ---: | ---: |
| Input ch0 | 217600 | 1.0 | 0.0754781223 | 35 | 0 / 0 |
| Input ch1 | 217600 | 1.0 | 0.0754781223 | 35 | 0 / 0 |
| Input ch2 | 217600 | 1.0 | 0.0754781223 | 35 | 0 / 0 |
| Render ch0 | 217600 | 0.6877746582 | 0.0681643701 | 0 | 0 / 0 |
| Render ch1 | 217600 | 0 | 0 | 0 | 0 / 0 |
| Render ch2 | 217600 | 0 | 0 | 0 | 0 / 0 |

Input三声道在本次所有原生buffer内重新核对为**逐样本字节相同**，并非只凭统计量相同推断。每声道满幅35个，其中+1.0为25个、−1.0为10个。这是触顶观察，不是可听削波、真人损伤或无损保证；须留给以后另获授权的内容试听，不能以AGC=true或RMS解释掉。保留全部原始声道，不假设“1mic+2reference”。

本次没有通过RMS/VAD判断人声合格、残回声或AEC增益，也没有比较/读取历史A/B私人PCM。

## 9. 封存、资源、配置通知与清理

| 项目 | 本轮结果 |
| --- | --- |
| writtenRecords / PCM | 272条；5222400 bytes，约4.98MiB，小于64MiB |
| Recorder residentBytes | 4473728 bytes，约4.27MiB，小于8MiB；不是整进程RSS |
| lost / overflow / pending | 0 / 0 / 0 |
| discarded / suppressed / INVALID | 0 / 0 / 0；未记录INVALID_CONTENTION |
| 缺hostTime / sampleTime | 0 / 0 |
| continuityUnknownRecords | 2，分别为两路首记录尚无前驱；后续原sample递推均通过，不伪称初始已有前驱 |
| sealed / controlSealSucceeded / integrity | true / true / VERIFIED；48字节seal receipt存在并由原validator一并核验 |
| 原生最终状态 | `SEALED_EVIDENCE`；manifest为`VPC_SEALED_ACOUSTICS_UNVERIFIED`，无primary/secondary诊断 |
| 通用摘要限制 | outcome仍为coverageStatus=MINIMUM_STREAM_PRESENCE、timestampStatus=UNVERIFIED；没有改写成通用PASS。正式窗具体证据来自C专用覆盖分析及原始时间检查 |
| 运行后设备释放 | engine.isRunning=false、player.isPlaying=false；无Engine后检输入deviceRunningSomewhere=0，默认设备/音量/Mic Mode未变 |

未记录导致INVALID的配置变更通知，stderr为空；不存在独立的通知总数测量，不能据此宣称所有异步TOCTOU均已排除。配置监听、stop、各Tap移除和seal沿原唯一清理路径执行，源码未改。没有单独新增实机removeTap/observer调用计数器或重建第二个Engine来验证释放。

**独立verify：**首次离线命令由执行者误传容器文件路径，返回1；公开CLI要求的是证据目录。保留该次诊断，按原CLI契约用同一封存目录纠正参数后，verify返回0、container_complete=true、invalid_reasons=0、272条/5222400 bytes。此为非设备核验参数纠正，不是重录、改校验器或替换证据；原数据未改。封存容器校验同时检查footer、checksum及seal receipt，只证明结构/完整性，不证明声源或AEC。

没有诊断预算、写盘、seal、连续性、路由或VP状态失败；没有第一工程失败原因需要覆盖或归因Apple。post-roll证据限制、满幅观察和物理/内容未知独立保留。

## 10. 现场反馈与四维判定

采集结束后询问：居民是否真实外放；真人连续讲话时居民是否仍同时讲话超过1秒；是否自然说完整句及提示可见；有无其他声音、超窗/漏词或设备/音量/增益/Mic Mode变化。用户原答：**“1、2、3、4都确认正常”。**

此答作有限现场见证，支持用户报告的同时发声及正常执行；不是测量级持续时长，不替代封存Input内容试听。不能仅凭反馈确认真人首尾已被Apple保留，或居民回声已被抑制。

| 维度 | 裁定与边界 |
| --- | --- |
| ENGINEERING_VALIDITY | **ENGINEERING_VALID，REVIEW_PENDING**：原状态、路由、正式双流覆盖、素材匹配、提示、连续性、资源及封存支持；post-roll另列UNVERIFIED |
| PHYSICAL_OVERLAP_EVIDENCE | **EVIDENCE_UNVERIFIED**；附数字播放与用户报告“同时讲话超过1秒”的有限见证，精确时长、空气传播及同轮Input内容未核验 |
| NEAR_END_PRESERVATION | **EVIDENCE_UNVERIFIED**；未试听本次Input的整句、首词“绿色”、尾词“这句话”、连续性听感、泵动/杂音/失真及满幅可听后果 |
| ECHO_RESIDUAL | **EVIDENCE_UNVERIFIED**；未听辨本次居民残回声或双讲中的回声反弹；不以低幅度/Render匹配判成功 |

没有ENGINEERING_FAILURE或Apple VP ACOUSTIC_FAILURE裁定；不授予DOUBLE_TALK_PRESERVED、VP-C PASS、AEC PASS或sourceAttributionConfirmed。后三个声学维度需以后单独授权的人工内容审核，不在本轮自动进行。

## 11. TECHNICAL_REVIEW / ENGINEERING_REVIEW / EVIDENCE_REVIEW

**TECHNICAL_REVIEW：DEVICE_DIGITAL_PATH_SUPPORTED / ACOUSTICS_UNVERIFIED。** 已批准VP_ON路径真实运行，双端enabled、bypass/mute关闭、同Engine数字播放与完整素材对应可审。node仍呈现Built-in，USB唯一物理来源未确认，不重开排他取证，不把VP整体作用等同纯AEC。

**ENGINEERING_REVIEW：ENGINEERING_VALID / REVIEW_PENDING。** 唯一一次采集支持固定正式窗、控制迟到门、双流原生连续性和封存规则。post-roll端锚、泛化异步清理证明及未独立profiling的系统性能限制如实保留；没有据exit0单独宣布有效。

**EVIDENCE_REVIEW：DIGITAL_EVIDENCE_VERIFIED / ACOUSTIC_CONTENT_UNVERIFIED。** 现有证据够供主控审核数字工程与后续内容审核价值；不够给出声学通过。只有本次被授权的原生数据被用于数字读取，无Input试听、导出、ASR或云端处理。

## 12. Stage7 Forbidden Checklist与停止

| 检查 | 裁定 |
| --- | --- |
| Stage/macOS/六红线 | PASS；仅Stage7.5独立研究，无新平台target或Stage8 |
| Qwen/Provider/Runtime/Test2 | PASS；无调用/代码/正式I/O/Runtime API/generation/身份/取消机制变化，无资格授予、interrupt/cancel/clear |
| DR/Studio/Memory/Session/Store/调度/UI | PASS；生产系统与schema均未改，无新所有权或后台功能 |
| 冻结实现与历史合同 | PASS；Driver、Tap、C/header、生命周期及工具源码零修改；01–22、正式Test3合同、ACE3不变，不操作原ACE3工作区或SSD/quarantine |
| 设备授权 | PASS；本轮私人读取、素材手动核验和现场外放/录音分别明确确认，再由用户原生确认；一次VP_ON，不重试、不切臂、无后续设备实验 |
| 私人与Git边界 | PASS；只新增本文，私人PCM/素材、WAV、设备UID/摘要、登记、原始日志、素材SHA及私人绝对路径均不入Git |

Stage7结论：**PASS**。触碰红线：无。修改文件：仅本文。是否改代码/Runtime API/DR schema/新增平台target/进入Stage8：均否。检查表旧语音路线文字不作为重构或替换当前冻结主链的依据；本轮没有生产架构变动。

```text
VP-A/B Research = CLOSED_FOR_NOW
VP-C Device Run = COMPLETED_ONCE / REVIEW_PENDING
VP-C Additional Device Run = NOT_AUTHORIZED
VP-C Acoustic Evidence = EVIDENCE_UNVERIFIED
VP-D/E = NOT_AUTHORIZED
Runtime Integration = NOT_AUTHORIZED
USB Unique Source = UNVERIFIED
Apple AEC Formal PASS = NOT_ESTABLISHED
Test3 = BLOCKED
Test3.execution_authorized = false
```

完成本次脱敏报告提交推送后停止，等待主控独立复审；不自动试听或进入下一阶段。
